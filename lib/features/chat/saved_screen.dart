import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Your saved messages (bookmarks) across all conversations. Tap to open the
/// conversation it lives in.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<SavedItem>? _items;
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
      final items = await ChatRepository.instance.savedMessages();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load saved messages.";
      });
    }
  }

  void _open(SavedItem s) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: s.channelId,
            channelName: s.channelName,
            kind: s.channelKind,
            isDm: s.isDm,
          ),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved messages')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final list = _items ?? [];
    if (list.isEmpty) return _centered('No saved messages yet.');
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = list[i];
        final label = s.isDm ? s.channelName : '#${s.channelName}';
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.bookmark, size: 20)),
          title: Text('${s.message.authorName} · $label',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s.message.body,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: s.message.createdAt != null
              ? Text(formatMessageTimestamp(s.message.createdAt!),
                  style: TextStyle(color: cs.outline, fontSize: 11))
              : null,
          onTap: () => _open(s),
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
