import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'channel_screen.dart';
import 'chat_repository.dart';
import 'notifications_provider.dart';

/// The in-app notification feed: recent messages received from others, tapping
/// one opens that conversation.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: state.items.isEmpty
          ? Center(
              child: Text('No notifications yet.',
                  style: TextStyle(color: cs.outline)))
          : ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final n = state.items[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(_initials(n.userName))),
                  title: Text(n.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(_time(n.createdAt),
                      style: TextStyle(color: cs.outline, fontSize: 11)),
                  onTap: () => _open(context, ref, n),
                );
              },
            ),
    );
  }

  Future<void> _open(
      BuildContext context, WidgetRef ref, AppNotification n) async {
    try {
      // Switch to the message's workspace first (cross-workspace notification).
      final auth = ref.read(authControllerProvider);
      if (n.tenantId != null && n.tenantId != auth.tenantId) {
        await ref
            .read(authControllerProvider.notifier)
            .switchWorkspace(n.tenantId!);
        if (!context.mounted) return;
      }
      final info = await ChatRepository.instance.channelInfo(n.channelId);
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChannelScreen(
          channelId: info.id,
          channelName: info.title,
          kind: info.kind,
          isDm: info.isDm,
          highlightMessageId: n.messageId,
        ),
      ));
    } on DioException {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    return '$h:${l.minute.toString().padLeft(2, '0')} $ampm';
  }
}
