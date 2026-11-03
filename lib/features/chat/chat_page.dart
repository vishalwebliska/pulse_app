import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// The Chat tab: the workspace's channel list. Tapping a channel opens it.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<PulseChannel>? _channels;
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
      final chs = await ChatRepository.instance.channels();
      if (!mounted) return;
      setState(() {
        _channels = chs;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? "Pulse isn't enabled for this workspace yet."
            : "Couldn't load channels. Pull down to retry.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final channels = _channels ?? [];
    if (channels.isEmpty) return _centered('No channels yet.');
    return ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = channels[i];
        return ListTile(
          leading: CircleAvatar(
            child: Icon(c.isPrivate ? Icons.lock_outline : Icons.tag),
          ),
          title: Text(c.name),
          subtitle: (c.topic != null && c.topic!.isNotEmpty)
              ? Text(c.topic!, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          trailing: c.unreadCount > 0 ? _badge(c.unreadCount) : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChannelScreen(
                channelId: c.id,
                channelName: c.name,
                kind: c.kind,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(int n) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(n > 99 ? '99+' : '$n',
          style: TextStyle(color: cs.onPrimary, fontSize: 12)),
    );
  }

  // A scrollable so RefreshIndicator works even when there's nothing to show.
  Widget _centered(String message) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(child: Text(message, style: TextStyle(color: cs.outline))),
      ],
    );
  }
}
