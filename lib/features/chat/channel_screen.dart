import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/realtime.dart';
import '../../core/token_store.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'pinned_screen.dart';
import 'search_screen.dart';
import 'thread_screen.dart';

/// A single conversation: message history + composer. Works for both regular
/// channels and DMs (set [isDm]). Live messages arrive over Reverb; sends also
/// append locally. The composer offers @-mention autocomplete; long-pressing a
/// message opens reactions + actions (copy, delete your own).
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
  int? _userId;
  PulseRealtime? _realtime;
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  // @-mention autocomplete
  List<PulseMember> _members = [];
  List<PulseMember> _mentionSuggestions = [];
  int _mentionAnchor = -1; // index of the active '@'

  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '🎉', '👀', '✅'];

  @override
  void initState() {
    super.initState();
    _loadUserId();
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

  Future<void> _loadUserId() async {
    final id = await TokenStore.instance.readUserId();
    if (mounted) setState(() => _userId = id);
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
    _markRead();
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
      _markRead();
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

  /// Mark this conversation read up to the newest message (clears the unread
  /// badge). Best-effort; works for channels and DMs.
  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    try {
      await ChatRepository.instance
          .markRead(widget.channelId, _messages.last.id);
    } on DioException {
      // Best-effort; the badge will clear on the next successful read.
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

  // ---- Reactions + message actions ----

  void _showMessageActions(PulseMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final e in _quickEmojis)
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleReaction(m, e);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Reply in thread'),
              onTap: () {
                Navigator.pop(ctx);
                _openThread(m);
              },
            ),
            ListTile(
              leading:
                  Icon(m.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(m.isPinned ? 'Unpin message' : 'Pin message'),
              onTap: () {
                Navigator.pop(ctx);
                _togglePin(m);
              },
            ),
            ListTile(
              leading:
                  Icon(m.isSaved ? Icons.bookmark : Icons.bookmark_border),
              title: Text(m.isSaved ? 'Remove from saved' : 'Save message'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleSave(m);
              },
            ),
            if (_userId != null && m.userId == _userId)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(m);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(ctx);
                _copy(m);
              },
            ),
            if (_userId != null && m.userId == _userId)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete message'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _copy(PulseMessage m) {
    Clipboard.setData(ClipboardData(text: m.body));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _toggleReaction(PulseMessage m, String emoji) async {
    final uid = _userId;
    if (uid == null) return;
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    final had =
        _messages[idx].reactions.any((r) => r.emoji == emoji && r.userId == uid);
    final updated = [..._messages[idx].reactions];
    if (had) {
      updated.removeWhere((r) => r.emoji == emoji && r.userId == uid);
    } else {
      updated.add(MessageReaction(userId: uid, emoji: emoji));
    }
    setState(() {
      _messages[idx] = _messages[idx].copyWith(reactions: updated);
      _messages = [..._messages];
    });
    try {
      if (had) {
        await ChatRepository.instance.removeReaction(m.id, emoji);
      } else {
        await ChatRepository.instance.addReaction(m.id, emoji);
      }
    } on DioException {
      _load(); // reconcile with the server on failure
    }
  }

  Future<void> _confirmDelete(PulseMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes the message for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatRepository.instance.deleteMessage(m.id);
      if (!mounted) return;
      setState(() => _messages = _messages.where((x) => x.id != m.id).toList());
    } on DioException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete the message.")),
      );
    }
  }

  Future<void> _editMessage(PulseMessage m) async {
    final ctrl = TextEditingController(text: m.body);
    final newBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || newBody == null || newBody.isEmpty || newBody == m.body) {
      return;
    }
    try {
      final updated = await ChatRepository.instance.editMessage(m.id, newBody);
      if (!mounted) return;
      final idx = _messages.indexWhere((x) => x.id == m.id);
      if (idx < 0) return;
      setState(() {
        _messages[idx] = _messages[idx].copyWith(
          body: updated.body,
          editedAt: updated.editedAt ?? DateTime.now(),
        );
        _messages = [..._messages];
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      final msg = (code == 422 || code == 403)
          ? 'You can only edit your own recent messages.'
          : "Couldn't edit the message.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
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
            Flexible(
                child: Text(widget.channelName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pinned messages',
            onPressed: _openPins,
            icon: const Icon(Icons.push_pin_outlined),
          ),
          IconButton(
            tooltip: 'Search this conversation',
            onPressed: _openChannelSearch,
            icon: const Icon(Icons.search),
          ),
        ],
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
    return GestureDetector(
      onLongPress: () => _showMessageActions(m),
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
                if (m.editedAt != null) ...[
                  const SizedBox(width: 6),
                  Text('(edited)',
                      style: TextStyle(
                          color: cs.outline,
                          fontSize: 11,
                          fontStyle: FontStyle.italic)),
                ],
                if (m.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin, size: 12, color: cs.outline),
                ],
              ],
            ),
            const SizedBox(height: 2),
            _body(m.body),
            _reactionChips(m),
            _replyCountRow(m),
          ],
        ),
      ),
    );
  }

  Widget _replyCountRow(PulseMessage m) {
    if (m.replyCount <= 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => _openThread(m),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                m.replyCount == 1 ? '1 reply' : '${m.replyCount} replies',
                style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openThread(PulseMessage m) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ThreadScreen(
            parentMessageId: m.id,
            channelName: widget.channelName,
          ),
        ))
        .then((_) => _load());
  }

  Future<void> _togglePin(PulseMessage m) async {
    final idx = _messages.indexWhere((x) => x.id == m.id);
    final wasPinned = m.isPinned;
    if (idx >= 0) {
      setState(() {
        _messages[idx] = _messages[idx].copyWith(isPinned: !wasPinned);
        _messages = [..._messages];
      });
    }
    try {
      if (wasPinned) {
        await ChatRepository.instance.unpinMessage(m.id);
      } else {
        await ChatRepository.instance.pinMessage(m.id);
      }
    } on DioException {
      if (!mounted) return;
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(isPinned: wasPinned);
          _messages = [..._messages];
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update the pin.")),
      );
    }
  }

  Future<void> _toggleSave(PulseMessage m) async {
    final idx = _messages.indexWhere((x) => x.id == m.id);
    final wasSaved = m.isSaved;
    if (idx >= 0) {
      setState(() {
        _messages[idx] = _messages[idx].copyWith(isSaved: !wasSaved);
        _messages = [..._messages];
      });
    }
    try {
      if (wasSaved) {
        await ChatRepository.instance.unsaveMessage(m.id);
      } else {
        await ChatRepository.instance.saveMessage(m.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wasSaved ? 'Removed from saved' : 'Saved')),
      );
    } on DioException {
      if (!mounted) return;
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(isSaved: wasSaved);
          _messages = [..._messages];
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update saved.")),
      );
    }
  }

  void _openPins() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PinnedScreen(
        channelId: widget.channelId,
        channelName: widget.channelName,
      ),
    ));
  }

  void _openChannelSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(
        channelId: widget.channelId,
        channelName: widget.channelName,
      ),
    ));
  }

  Widget _reactionChips(PulseMessage m) {
    if (m.reactions.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in m.reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (_userId != null && r.userId == _userId) mine.add(r.emoji);
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            GestureDetector(
              onTap: () => _toggleReaction(m, entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: mine.contains(entry.key)
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: mine.contains(entry.key)
                        ? cs.primary
                        : cs.outlineVariant,
                  ),
                ),
                child: Text('${entry.key} ${entry.value}',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
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
            subtitle:
                Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  String _time(DateTime dt) => formatMessageTimestamp(dt);
}
