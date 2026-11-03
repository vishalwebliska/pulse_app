import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/realtime.dart';
import '../../core/token_store.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// A single conversation: message history + composer. Works for both regular
/// channels and DMs (set [isDm]). Live messages arrive over Reverb; sends also
/// append locally. The composer offers @-mention autocomplete from the
/// workspace directory.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.kind,
    this.isDm = false,
  });

  final int channelId;
  final String channelName;
  final String kind;
  final bool isDm;

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
  PulseRealtime? _realtime;
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  // @-mention autocomplete
  List<PulseMember> _members = [];
  List<PulseMember> _mentionSuggestions = [];
  int _mentionAnchor = -1; // index of the active '@'

  @override
  void initState() {
    super.initState();
    _load();
    _initRealtime();
    _loadMembers();
    _composer.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _composer.removeListener(_onComposerChanged);
    _rtSub?.cancel();
    _realtime?.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initRealtime() async {
    final tenantId = await TokenStore.instance.readTenant();
    if (tenantId == null || !mounted) return;
    final rt = PulseRealtime(tenantId);
    _realtime = rt;
    rt.connect();
    _rtSub = rt.onMessage.listen(_onLiveMessage);
  }

  Future<void> _loadMembers() async {
    try {
      final people = await ChatRepository.instance.directory();
      if (!mounted) return;
      setState(() => _members = people);
    } on DioException {
      // Mentions still type fine without the picker; ignore.
    }
  }

  void _onLiveMessage(Map<String, dynamic> p) {
    if (!mounted) return;
    if ((p['channel_id'] as int?) != widget.channelId) return;
    if (p['parent_message_id'] != null) return; // thread reply, not the main list
    final id = p['message_id'] as int;
    if (_messages.any((m) => m.id == id)) return; // dedup (incl. our own echo)
    final msg = PulseMessage(
      id: id,
      userId: p['user_id'] as int?,
      body: (p['body'] ?? '') as String,
      bodyRendered: p['body_rendered'] as String?,
      kind: 'user',
      authorName: (p['user_name'] ?? 'Someone') as String,
      createdAt: p['created_at'] != null
          ? DateTime.tryParse(p['created_at'] as String)
          : null,
    );
    setState(() => _messages = [..._messages, msg]);
    _jumpToBottom();
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
            ? "You can't view this conversation."
            : "Couldn't load messages.";
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = widget.isDm
          ? await ChatRepository.instance.sendDm(widget.channelId, text)
          : await ChatRepository.instance.send(widget.channelId, text);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _composer.clear();
        _sending = false;
      });
      _clearMentions();
      _jumpToBottom();
    } on DioException {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message not sent.')),
      );
    }
  }

  // ---- @-mention autocomplete ----

  void _onComposerChanged() {
    final sel = _composer.selection;
    final text = _composer.text;
    if (!sel.isValid || sel.start != sel.end) {
      _clearMentions();
      return;
    }
    final caret = sel.start;
    final upto = text.substring(0, caret);
    final at = upto.lastIndexOf('@');
    if (at < 0) {
      _clearMentions();
      return;
    }
    // The '@' must start the word (beginning of text or after whitespace).
    if (at > 0 && !RegExp(r'\s').hasMatch(upto[at - 1])) {
      _clearMentions();
      return;
    }
    final query = upto.substring(at + 1);
    if (query.contains(RegExp(r'\s'))) {
      _clearMentions();
      return;
    }
    _mentionAnchor = at;
    final q = query.toLowerCase();
    final matches = _members
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            m.email.toLowerCase().contains(q))
        .take(6)
        .toList();
    setState(() => _mentionSuggestions = matches);
  }

  void _clearMentions() {
    if (_mentionSuggestions.isEmpty && _mentionAnchor < 0) return;
    setState(() {
      _mentionSuggestions = [];
      _mentionAnchor = -1;
    });
  }

  void _applyMention(PulseMember m) {
    final text = _composer.text;
    final caret = _composer.selection.start;
    if (_mentionAnchor < 0 || caret < _mentionAnchor) {
      _clearMentions();
      return;
    }
    final before = text.substring(0, _mentionAnchor);
    final after = text.substring(caret);
    final insert = '@${m.mentionToken} ';
    final newText = '$before$insert$after';
    _composer.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (before + insert).length),
    );
    _clearMentions();
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
    final leadingIcon = widget.isDm
        ? (widget.kind == 'group_dm' ? Icons.group_outlined : Icons.person_outline)
        : (widget.kind == 'private' ? Icons.lock_outline : Icons.tag);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leadingIcon, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(widget.channelName, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          if (_mentionSuggestions.isNotEmpty) _buildMentionBar(),
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
          _body(m.body),
        ],
      ),
    );
  }

  /// Renders the message body with @mentions highlighted.
  Widget _body(String body) {
    final cs = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style;
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
    return RichText(text: TextSpan(style: base, children: spans));
  }

  Widget _buildMentionBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionSuggestions.length,
        itemBuilder: (context, i) {
          final m = _mentionSuggestions[i];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              child: Text(_initials(m.name), style: const TextStyle(fontSize: 11)),
            ),
            title: Text(m.name),
            subtitle: Text(m.email,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _applyMention(m),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    final hint = widget.isDm
        ? 'Message ${widget.channelName}'
        : 'Message #${widget.channelName}';
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
                  hintText: hint,
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
