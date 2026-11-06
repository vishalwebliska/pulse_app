import 'dart:async';
import 'dart:convert';

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
    this.tenantId,
  });

  final int channelId;
  final int? messageId;
  final int? userId;
  final String userName;
  final String body;
  final DateTime createdAt;

  /// The workspace this message belongs to. It may differ from the workspace
  /// you're currently viewing (Skype-style: a message from anyone, in any of
  /// your workspaces, notifies you), so opening it switches workspace first.
  final String? tenantId;
}

/// Notification feed state: the recent items + how many are unseen (for the bell
/// badge). The newest item is first.
class NotifState {
  const NotifState(this.items, this.unseen);
  final List<AppNotification> items;
  final int unseen;
}

/// Global realtime → in-app notifications. While alive (watched by the app
/// shell) it connects to the Reverb channel of **every** workspace you belong
/// to and turns messages from others — outside the conversation you're viewing —
/// into notifications, no matter which workspace is on screen.
class Notifications extends Notifier<NotifState> {
  final List<PulseRealtime> _rts = [];
  final List<StreamSubscription<Map<String, dynamic>>> _subs = [];
  int? _myUserId;

  @override
  NotifState build() {
    _start();
    ref.onDispose(_teardown);
    return const NotifState([], 0);
  }

  Future<void> _start() async {
    _myUserId = await TokenStore.instance.readUserId();
    // Subscribe to EVERY workspace, so a message from anyone — even in a
    // workspace you're not viewing — raises a notification (Skype-style).
    final workspaceIds = await _allWorkspaceIds();
    for (final wsId in workspaceIds) {
      final rt = PulseRealtime(wsId);
      rt.connect();
      _rts.add(rt);
      _subs.add(rt.onMessage.listen((p) => _onMessage(p, wsId)));
    }
  }

  /// Every workspace id the user belongs to — the active tenant plus the stored
  /// workspace list — de-duplicated.
  Future<List<String>> _allWorkspaceIds() async {
    final ids = <String>{};
    final current = await TokenStore.instance.readTenant();
    if (current != null && current.isNotEmpty) ids.add(current);
    final raw = await TokenStore.instance.readWorkspaces();
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final w in (jsonDecode(raw) as List)) {
          final id = (w is Map) ? w['id']?.toString() : null;
          if (id != null && id.isNotEmpty) ids.add(id);
        }
      } catch (_) {
        // Malformed cache — the active tenant above still gets us notifications.
      }
    }
    return ids.toList();
  }

  void _onMessage(Map<String, dynamic> p, String tenantId) {
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
      tenantId: tenantId,
    );
    state = NotifState(
      [n, ...state.items].take(50).toList(),
      state.unseen + 1,
    );
  }

  /// Re-subscribe to the current workspace set — e.g. after someone connects you
  /// to a new workspace, or you switch/add one. Safe to call repeatedly.
  Future<void> refresh() async {
    _teardown();
    await _start();
  }

  /// Clear the unseen badge (the feed items are kept).
  void markAllSeen() => state = NotifState(state.items, 0);

  void _teardown() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final r in _rts) {
      r.dispose();
    }
    _subs.clear();
    _rts.clear();
  }
}

final notificationsProvider =
    NotifierProvider<Notifications, NotifState>(Notifications.new);
