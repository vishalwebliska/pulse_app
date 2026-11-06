import 'package:flutter/foundation.dart';

/// Where a tapped push wants to take the user: a conversation, optionally a
/// specific message to jump to + flash, optionally in another workspace.
@immutable
class PushTarget {
  const PushTarget({
    required this.channelId,
    this.messageId,
    this.tenantId,
  });

  final int channelId;
  final int? messageId;
  final String? tenantId;
}

/// Set by the FCM tap handler ([PushService]); watched by the app shell
/// ([HomeShell]) which opens the conversation and flashes the message.
///
/// A plain global [ValueNotifier] rather than a Riverpod provider: the FCM
/// callbacks fire outside the widget tree (and from a terminated-state cold
/// start, before any provider scope exists), and Riverpod 3 dropped
/// `StateProvider`. The shell consumes + clears the value, so a target set
/// before the shell mounts (cold start from a notification) is still handled.
final ValueNotifier<PushTarget?> pendingPushTarget =
    ValueNotifier<PushTarget?>(null);

/// Parse a push message's `data` map into a [PushTarget], or null if it does
/// not point at a conversation. Prefers the `url` deep link (carried by every
/// push transport — `flaxxapulse://chat?channel=..&message=..&tenant=..`), and
/// falls back to discrete `channel_id` / `message_id` / `tenant_id` keys (the
/// OmnioSuite transport forwards the whole data array).
PushTarget? pushTargetFromData(Map<String, dynamic> data) {
  final url = data['url']?.toString();
  if (url != null && url.isNotEmpty) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final ch = int.tryParse(uri.queryParameters['channel'] ?? '');
      if (ch != null) {
        final tenant = uri.queryParameters['tenant'];
        return PushTarget(
          channelId: ch,
          messageId: int.tryParse(uri.queryParameters['message'] ?? ''),
          tenantId: (tenant == null || tenant.isEmpty) ? null : tenant,
        );
      }
    }
  }

  final ch = int.tryParse(data['channel_id']?.toString() ?? '');
  if (ch != null) {
    final tenant = data['tenant_id']?.toString();
    return PushTarget(
      channelId: ch,
      messageId: int.tryParse(data['message_id']?.toString() ?? ''),
      tenantId: (tenant == null || tenant.isEmpty) ? null : tenant,
    );
  }

  return null;
}
