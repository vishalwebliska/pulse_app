import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Your active reminders ("Remind me about this message") across conversations.
/// Tap one to open the conversation and flash the message; the trash icon
/// cancels it.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<PulseReminder>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatRepository.instance.reminders();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load reminders.";
      });
    }
  }

  Future<void> _cancel(PulseReminder r) async {
    // Optimistic remove.
    setState(() => _items = _items?.where((x) => x.id != r.id).toList());
    try {
      await ChatRepository.instance.deleteReminder(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reminder cancelled')));
    } on DioException {
      if (!mounted) return;
      _load(); // restore on failure
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't cancel the reminder.")));
    }
  }

  Future<void> _open(PulseReminder r) async {
    try {
      // Resolve the proper conversation title (DMs carry a display name).
      final info = await ChatRepository.instance.channelInfo(r.channelId);
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => ChannelScreen(
              channelId: info.id,
              channelName: info.title,
              kind: info.kind,
              isDm: info.isDm,
              highlightMessageId: r.messageId,
            ),
          ))
          .then((_) => _load());
    } on DioException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the conversation.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final list = _items ?? [];
    if (list.isEmpty) {
      return _centered('No reminders yet.\nUse a message\'s ⋯ → Remind me.');
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = list[i];
        final label = r.isDm
            ? (r.channelName.isEmpty ? 'Direct message' : r.channelName)
            : '#${r.channelName}';
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.schedule, size: 20)),
          title: Text(
            r.remindAt != null
                ? '${formatMessageTimestamp(r.remindAt!)} · $label'
                : label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            r.messageBody.isEmpty ? '(no text)' : r.messageBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Cancel reminder',
            icon: Icon(Icons.delete_outline, color: cs.outline),
            onPressed: () => _cancel(r),
          ),
          onTap: () => _open(r),
        );
      },
    );
  }

  Widget _centered(String msg) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(
          child: Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline)),
        ),
      ],
    );
  }
}
