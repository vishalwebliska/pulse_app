import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// Pick a conversation to forward a message into, with an optional note.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({
    super.key,
    required this.messageId,
    required this.preview,
  });

  final int messageId;
  final String preview;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final _comment = TextEditingController();
  List<PulseChannel> _targets = [];
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
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ChatRepository.instance.channels(),
        ChatRepository.instance.dms(),
      ]);
      if (!mounted) return;
      setState(() {
        _targets = [...results[0], ...results[1]];
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load conversations.";
      });
    }
  }

  Future<void> _forward(PulseChannel c) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ChatRepository.instance
          .forwardMessage(widget.messageId, c.id, comment: _comment.text);
      if (!mounted) return;
      final name = c.isDm ? c.title : '#${c.name}';
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Forwarded to $name')));
    } on DioException {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't forward.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Forward to…')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    widget.preview.isEmpty ? '(message)' : widget.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add a note (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_sending) const LinearProgressIndicator(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_targets.isEmpty) {
      return Center(
          child: Text('No conversations.', style: TextStyle(color: cs.outline)));
    }
    return ListView.separated(
      itemCount: _targets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = _targets[i];
        final icon = c.isDm
            ? (c.isGroupDm ? Icons.group_outlined : Icons.person_outline)
            : (c.isPrivate ? Icons.lock_outline : Icons.tag);
        return ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(c.isDm ? c.title : c.name),
          onTap: _sending ? null : () => _forward(c),
        );
      },
    );
  }
}
