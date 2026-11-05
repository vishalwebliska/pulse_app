import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/token_store.dart';
import 'attachment_view.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'composer_toolbar.dart';
import 'emoji_picker.dart';
import 'forward_screen.dart';
import 'hover_actions.dart';
import 'message_text.dart';
import 'reminder_helpers.dart';

/// A message thread: the root message + its replies, with a composer to reply.
/// Opened from the "N replies" indicator or the message action sheet.
///
/// Message actions (react, copy, save, pin, forward, edit/delete your own) are
/// reachable the same way as the main chat: hover toolbar + right-click on
/// desktop, long-press on touch.
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
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  PulseMessage? _parent;
  List<PulseMessage> _replies = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int? _userId;

  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '🎉', '👀', '✅'];

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final id = await TokenStore.instance.readUserId();
    if (mounted) setState(() => _userId = id);
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

  // ---- Message mutation helpers (parent + replies) ----

  void _updateMessage(int id, PulseMessage Function(PulseMessage) fn) {
    setState(() {
      if (_parent != null && _parent!.id == id) {
        _parent = fn(_parent!);
      } else {
        _replies = _replies.map((r) => r.id == id ? fn(r) : r).toList();
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
            Flexible(
              child: Text(m.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
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
        AttachmentView(attachments: m.attachments),
        _reactionChips(m),
      ],
    );

    final gesture = GestureDetector(
      onLongPressStart: (d) => _showActions(m, d.globalPosition),
      onSecondaryTapDown: (d) => _showActions(m, d.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: isParent
          ? Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: inner,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 6), child: inner),
    );

    // Flat left-aligned rows → anchor the hover toolbar to the top-right.
    return HoverActions(
      isOwn: false,
      emojis: _quickEmojis,
      onReactEmoji: (e) => _toggleReaction(m, e),
      onMore: (pos) => _showActions(m, pos),
      child: gesture,
    );
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

  // ---- Actions ----

  Future<void> _showActions(PulseMessage m, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final cs = Theme.of(context).colorScheme;
    final isOwn = _userId != null && m.userId == _userId;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      // Cap the height so a near-bottom message's menu stays on-screen and
      // scrolls internally instead of being clipped off the bottom.
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      items: [
        PopupMenuItem<String>(
          padding: EdgeInsets.zero,
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in _quickEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).pop('react:$e'),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).pop('emojipick'),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.add_reaction_outlined,
                        size: 20, color: cs.outline),
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        _menuItem('pin', m.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            m.isPinned ? 'Unpin message' : 'Pin message'),
        _menuItem('save', m.isSaved ? Icons.bookmark : Icons.bookmark_border,
            m.isSaved ? 'Remove from saved' : 'Save message'),
        _menuItem('remind', Icons.schedule_outlined, 'Remind me'),
        _menuItem('forward', Icons.forward, 'Forward'),
        _menuItem('copy', Icons.copy, 'Copy text'),
        if (isOwn) _menuItem('edit', Icons.edit_outlined, 'Edit message'),
        if (isOwn) _menuItem('delete', Icons.delete_outline, 'Delete message'),
      ],
    );
    if (result == null || !mounted) return;
    if (result.startsWith('react:')) {
      _toggleReaction(m, result.substring(6));
      return;
    }
    if (result == 'emojipick') {
      final emoji = await showEmojiPicker(context);
      if (emoji != null && mounted) _toggleReaction(m, emoji);
      return;
    }
    switch (result) {
      case 'pin':
        _togglePin(m);
      case 'save':
        _toggleSave(m);
      case 'remind':
        remindAboutMessage(context, m.id);
      case 'forward':
        _forward(m);
      case 'copy':
        _copy(m);
      case 'edit':
        _editMessage(m);
      case 'delete':
        _confirmDelete(m);
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 19, color: cs.outline),
          const SizedBox(width: 12),
          Text(label),
        ],
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
    final had = m.reactions.any((r) => r.emoji == emoji && r.userId == uid);
    final updated = [...m.reactions];
    if (had) {
      updated.removeWhere((r) => r.emoji == emoji && r.userId == uid);
    } else {
      updated.add(MessageReaction(userId: uid, emoji: emoji));
    }
    _updateMessage(m.id, (x) => x.copyWith(reactions: updated));
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

  Future<void> _togglePin(PulseMessage m) async {
    final wasPinned = m.isPinned;
    _updateMessage(m.id, (x) => x.copyWith(isPinned: !wasPinned));
    try {
      if (wasPinned) {
        await ChatRepository.instance.unpinMessage(m.id);
      } else {
        await ChatRepository.instance.pinMessage(m.id);
      }
    } on DioException {
      _updateMessage(m.id, (x) => x.copyWith(isPinned: wasPinned));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update the pin.")),
        );
      }
    }
  }

  Future<void> _toggleSave(PulseMessage m) async {
    final wasSaved = m.isSaved;
    _updateMessage(m.id, (x) => x.copyWith(isSaved: !wasSaved));
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
      _updateMessage(m.id, (x) => x.copyWith(isSaved: wasSaved));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update saved.")),
        );
      }
    }
  }

  void _forward(PulseMessage m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ForwardScreen(messageId: m.id, preview: m.body),
    ));
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
    if (newBody == null || newBody.isEmpty || newBody == m.body) return;
    _updateMessage(
        m.id, (x) => x.copyWith(body: newBody, editedAt: DateTime.now()));
    try {
      await ChatRepository.instance.editMessage(m.id, newBody);
    } on DioException {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save your edit.")),
        );
      }
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
      if (_parent?.id == m.id) {
        Navigator.of(context).pop(); // thread root gone — leave the thread
      } else {
        setState(() => _replies = _replies.where((x) => x.id != m.id).toList());
      }
    } on DioException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete the message.")),
      );
    }
  }

  /// Renders the message body with inline Markdown + @mentions.
  Widget _body(String body) => messageBody(context, body);

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ComposerToolbar(controller: _composer, focusNode: _composerFocus),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    focusNode: _composerFocus,
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
          ],
        ),
      ),
    );
  }

  String _time(DateTime dt) => formatMessageTimestamp(dt);
}
