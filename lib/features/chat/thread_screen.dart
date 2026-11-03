import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// A message thread: the root message + its replies, with a composer to reply.
/// Opened from the "N replies" indicator or the message action sheet.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.parentMessageId,
    required this.channelName,
  });

  final int parentMessageId;
  final String channelName;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  PulseMessage? _parent;
  List<PulseMessage> _replies = [];
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
      final t = await ChatRepository.instance.thread(widget.parentMessageId);
      if (!mounted) return;
      setState(() {
        _parent = t.parent;
        _replies = t.replies;
        _loading = false;
      });
      _jumpToBottom();
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load the thread.";
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final reply = await ChatRepository.instance
          .replyInThread(widget.parentMessageId, text);
      if (!mounted) return;
      setState(() {
        _replies = [..._replies, reply];
        _composer.clear();
        _sending = false;
      });
      _jumpToBottom();
    } on DioException {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply not sent.')),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thread'),
            Text('#${widget.channelName}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
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
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      children: [
        if (_parent != null) _messageTile(_parent!, isParent: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(
                _replies.isEmpty
                    ? 'No replies yet'
                    : (_replies.length == 1
                        ? '1 reply'
                        : '${_replies.length} replies'),
                style: TextStyle(
                    color: cs.outline,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ],
          ),
        ),
        ..._replies.map((r) => _messageTile(r)),
      ],
    );
  }

  Widget _messageTile(PulseMessage m, {bool isParent = false}) {
    final cs = Theme.of(context).colorScheme;
    final inner = Column(
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
        _body(m.body),
      ],
    );
    if (!isParent) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: inner);
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: inner,
    );
  }

  /// Renders the message body with @mentions highlighted.
  Widget _body(String body) {
    final cs = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    final re = RegExp(r'@[^\s@]+');
    var last = 0;
    for (final match in re.allMatches(body)) {
      if (match.start > last) {
        spans.add(TextSpan(text: body.substring(last, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
      ));
      last = match.end;
    }
    if (last < body.length) spans.add(TextSpan(text: body.substring(last)));
    // Explicit body style + Text.rich guarantees a resolved text style,
    // avoiding Flutter's red/yellow "unstyled text" fallback.
    return Text.rich(
      TextSpan(children: spans),
      style: Theme.of(context).textTheme.bodyMedium,
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
                decoration: const InputDecoration(
                  hintText: 'Reply…',
                  border: OutlineInputBorder(),
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

  String _time(DateTime dt) => formatMessageTimestamp(dt);
}
