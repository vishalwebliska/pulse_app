import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// A single channel: message history + a composer. No realtime yet (Phase 1.5
/// swaps in Reverb); messages append locally on send, and pull-to-refresh/reopen
/// reloads from the server.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.kind,
  });

  final int channelId;
  final String channelName;
  final String kind;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  List<PulseMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await ChatRepository.instance.messages(widget.channelId);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _jumpToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? "You can't view this channel."
            : "Couldn't load messages.";
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await ChatRepository.instance.send(widget.channelId, text);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _composer.clear();
        _sending = false;
      });
      _jumpToBottom();
    } on DioException {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message not sent.')),
      );
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.kind == 'private' ? Icons.lock_outline : Icons.tag,
                size: 18),
            const SizedBox(width: 6),
            Text(widget.channelName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          const Divider(height: 1),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_messages.isEmpty) {
      return Center(
        child: Text('No messages yet. Say hello 👋',
            style: TextStyle(color: cs.outline)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _messageTile(_messages[i]),
    );
  }

  Widget _messageTile(PulseMessage m) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(m.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (m.createdAt != null)
                Text(_time(m.createdAt!),
                    style: TextStyle(color: cs.outline, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text(m.body),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message #${widget.channelName}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    return '$h:${l.minute.toString().padLeft(2, '0')} $ampm';
  }
}
