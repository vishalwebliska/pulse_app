import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../chat/channel_screen.dart';
import '../chat/chat_models.dart';
import '../chat/chat_repository.dart';

/// Activity: everywhere you were @-mentioned. Tap a mention to open the
/// conversation (and mark it read). Toggle to show only unread.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Mention>? _mentions;
  bool _loading = true;
  bool _unreadOnly = false;
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
      final list = await ChatRepository.instance
          .mentions(filter: _unreadOnly ? 'unread' : 'all');
      if (!mounted) return;
      setState(() {
        _mentions = list;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? "Pulse isn't enabled for this workspace yet."
            : "Couldn't load your mentions.";
      });
    }
  }

  Future<void> _open(Mention m) async {
    if (!m.read) {
      try {
        await ChatRepository.instance.markMentionRead(m.id);
      } on DioException {
        // best-effort
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelScreen(
        channelId: m.channelId,
        channelName: m.channelName,
        kind: m.channelKind,
        isDm: m.isDm,
        highlightMessageId: m.messageId,
      ),
    ));
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          Row(
            children: [
              const Text('Unread'),
              Switch(
                value: _unreadOnly,
                onChanged: (v) {
                  setState(() => _unreadOnly = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final list = _mentions ?? [];
    if (list.isEmpty) {
      return _centered(_unreadOnly ? 'No unread mentions.' : 'No mentions yet.');
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = list[i];
        final label =
            m.isDm ? m.channelName : '#${m.channelName}';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: m.read ? null : cs.primary,
            child: Icon(
              m.isDm ? Icons.person_outline : Icons.alternate_email,
              size: 20,
              color: m.read ? null : cs.onPrimary,
            ),
          ),
          title: Text(
            '${m.authorName} · $label',
            style: TextStyle(
                fontWeight: m.read ? FontWeight.w400 : FontWeight.w600),
          ),
          subtitle: Text(
            (m.body != null && m.body!.isNotEmpty)
                ? m.body!
                : '(message unavailable)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: m.mentionedAt != null
              ? Text(formatMessageTimestamp(m.mentionedAt!),
                  style: TextStyle(color: cs.outline, fontSize: 11))
              : null,
          onTap: () => _open(m),
        );
      },
    );
  }

  Widget _centered(String msg) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(child: Text(msg, style: TextStyle(color: cs.outline))),
      ],
    );
  }
}
