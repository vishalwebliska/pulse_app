import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../people/people_search_screen.dart';
import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'new_group_screen.dart';

/// The Chat tab: the workspace's channels + direct messages. A search button
/// finds people (and starts a DM); a group button creates a new group.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<PulseChannel>? _channels;
  List<PulseChannel>? _dms;
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
      // DMs are a separate endpoint; fetch both together.
      final results = await Future.wait([
        ChatRepository.instance.channels(),
        ChatRepository.instance.dms(),
      ]);
      if (!mounted) return;
      setState(() {
        _channels = results[0];
        _dms = results[1];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? "Pulse isn't enabled for this workspace yet."
            : "Couldn't load conversations. Pull down to retry.";
      });
    }
  }

  void _openPeopleSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PeopleSearchScreen()))
        .then((_) => _load());
  }

  void _openNewGroup() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewGroupScreen()))
        .then((_) => _load());
  }

  void _openConversation(PulseChannel c) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: c.id,
            channelName: c.title,
            kind: c.kind,
            isDm: c.isDm,
          ),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse'),
        actions: [
          IconButton(
            tooltip: 'Find people',
            onPressed: _openPeopleSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: _openNewGroup,
            icon: const Icon(Icons.group_add_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);

    final channels = _channels ?? [];
    final dms = _dms ?? [];
    if (channels.isEmpty && dms.isEmpty) {
      return _centered('No conversations yet.');
    }

    return ListView(
      children: [
        if (channels.isNotEmpty) _sectionHeader('Channels'),
        ...channels.map(_channelTile),
        if (dms.isNotEmpty) _sectionHeader('Direct messages'),
        ...dms.map(_dmTile),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: cs.outline,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _channelTile(PulseChannel c) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(c.isPrivate ? Icons.lock_outline : Icons.tag),
      ),
      title: Text(c.name),
      subtitle: (c.topic != null && c.topic!.isNotEmpty)
          ? Text(c.topic!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: c.unreadCount > 0 ? _badge(c.unreadCount) : null,
      onTap: () => _openConversation(c),
    );
  }

  Widget _dmTile(PulseChannel c) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(c.isGroupDm ? Icons.group_outlined : Icons.person_outline),
      ),
      title: Text(c.title),
      trailing: c.unreadCount > 0 ? _badge(c.unreadCount) : null,
      onTap: () => _openConversation(c),
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
