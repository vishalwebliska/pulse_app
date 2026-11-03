import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'config.dart';

/// Minimal Pusher-protocol client for Laravel Reverb (Phase 1.5 live chat).
///
/// Connects to the Reverb socket, authorizes the private per-workspace channel
/// with the Bearer token (via the mobile broadcasting-auth endpoint), and streams
/// `message.sent` payloads. Degrades silently when Reverb is unreachable — the app
/// still works on pull-to-refresh.
class PulseRealtime {
  PulseRealtime(this.tenantId);

  final String tenantId;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  String? _socketId;
  bool _closed = false;

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<Map<String, dynamic>>.broadcast();

  /// Parsed `message.sent` payloads (channel_id, message_id, user_name, body, …).
  Stream<Map<String, dynamic>> get onMessage => _messages.stream;

  /// Parsed `member.typing` payloads (channel_id, user_id, parent_message_id, expires_at).
  Stream<Map<String, dynamic>> get onTyping => _typing.stream;

  String get _channel => 'private-pulse.workspace.$tenantId';

  void connect() {
    final url = '${AppConfig.reverbScheme}://${AppConfig.reverbHost}:'
        '${AppConfig.reverbPort}/app/${AppConfig.reverbKey}'
        '?protocol=7&client=flutter&version=1.0';
    try {
      _ws = WebSocketChannel.connect(Uri.parse(url));
      _sub = _ws!.stream.listen(_onFrame, onError: (_) {}, onDone: () {});
    } catch (_) {
      // Reverb unreachable → no live updates; app falls back to manual refresh.
    }
  }

  Future<void> _onFrame(dynamic raw) async {
    if (_closed) return;
    Map<String, dynamic> frame;
    try {
      frame = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (frame['event'] as String?) {
      case 'pusher:connection_established':
        final d =
            (jsonDecode(frame['data'] as String) as Map).cast<String, dynamic>();
        _socketId = d['socket_id'] as String?;
        await _subscribe();
        break;
      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': <String, dynamic>{}});
        break;
      case 'message.sent':
        final data = frame['data'];
        final payload = data is String ? jsonDecode(data) : data;
        if (payload is Map) {
          _messages.add(payload.cast<String, dynamic>());
        }
        break;
      case 'member.typing':
        final tData = frame['data'];
        final tPayload = tData is String ? jsonDecode(tData) : tData;
        if (tPayload is Map) {
          _typing.add(tPayload.cast<String, dynamic>());
        }
        break;
      default:
        break; // subscription_succeeded, errors, etc.
    }
  }

  Future<void> _subscribe() async {
    if (_socketId == null) return;
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/mobile/broadcasting/auth',
        data: {'socket_id': _socketId, 'channel_name': _channel},
      );
      final auth = (res.data as Map)['auth'] as String?;
      if (auth == null) return;
      _send({
        'event': 'pusher:subscribe',
        'data': {'channel': _channel, 'auth': auth},
      });
    } catch (_) {
      // Auth failed → no live updates; manual refresh still works.
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void dispose() {
    _closed = true;
    _sub?.cancel();
    try {
      _ws?.sink.close();
    } catch (_) {}
    _messages.close();
    _typing.close();
  }
}
