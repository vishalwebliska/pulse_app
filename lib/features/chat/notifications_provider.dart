import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime.dart';
import '../../core/token_store.dart';

/// The conversation currently open on screen, so the global listener doesn't
/// raise a notification for a message you're already looking at. Set by
/// ChannelScreen while it's mounted (a plain global — no rebuilds needed).
int? activeChannelId;

/// An in-app notification for a message received from someone else.
class AppNotification {
  AppNotification({
    required this.channelId,
    required this.messageId,
    required this.userId,
    required this.userName,
    required this.body,
    required this.createdAt,
  });

  final int channelId;
  final int? messageId;
  final int? userId;
  final String userName;
  final String body;
  final DateTime createdAt;
}

/// Notification feed state: the recent items + how many are unseen (for the bell
/// badge). The newest item is first.
class NotifState {
  const NotifState(this.items, this.unseen);
  final List<AppNotification> items;
  final int unseen;
}

/// Global realtime → in-app notifications. While alive (watched by the app
/// shell) it connects to the workspace Reverb channel and turns messages from
/// others — outside the conversation you're viewing — into notifications.
class Notifications extends Notifier<NotifState> {
  PulseRealtime? _rt;
  StreamSubscription<Map<String, dynamic>>? _sub;
  int? _myUserId;

  @override
  NotifState build() {
    _start();
    ref.onDispose(() {
      _sub?.cancel();
      _rt?.dispose();
    });
    return const NotifState([], 0);
  }

  Future<void> _start() async {
    _myUserId = await TokenStore.instance.readUserId();
    final tenant = await TokenStore.instance.readTenant();
    if (tenant == null) return;
    final rt = PulseRealtime(tenant);
    _rt = rt;
    rt.connect();
    _sub = rt.onMessage.listen(_onMessage);
  }

  void _onMessage(Map<String, dynamic> p) {
    if (p['parent_message_id'] != null) return; // thread reply, not the main list
    final uid = p['user_id'] as int?;
    if (uid != null && uid == _myUserId) return; // my own message
    final channelId = p['channel_id'] as int?;
    if (channelId == null) return;
    if (channelId == activeChannelId) return; // you're viewing this conversation
    final n = AppNotification(
      channelId: channelId,
      messageId: p['message_id'] as int?,
      userId: uid,
      userName: (p['user_name'] ?? 'Someone') as String,
      body: (p['body'] ?? '') as String,
      createdAt: p['created_at'] != null
          ? (DateTime.tryParse(p['created_at'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
    state = NotifState(
      [n, ...state.items].take(50).toList(),
      state.unseen + 1,
    );
  }

  /// Clear the unseen badge (the feed items are kept).
  void markAllSeen() => state = NotifState(state.items, 0);
}

final notificationsProvider =
    NotifierProvider<Notifications, NotifState>(Notifications.new);
