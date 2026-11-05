import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/realtime.dart';
import '../../core/token_store.dart';
import 'attachment_view.dart';
import 'channel_details_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'composer_toolbar.dart';
import 'forward_screen.dart';
import 'hover_actions.dart';
import 'message_text.dart';
import 'notifications_provider.dart';
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
    this.highlightMessageId,
  });

  final int channelId;
  final String channelName;
  final String kind;
  final bool isDm;

  /// When opened from a notification: the message to scroll to and briefly
  /// flash once the history loads.
  final int? highlightMessageId;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  List<PulseMessage> _messages = [];
  bool _loading = true;
  int _nextTempId = -1;
  final List<_Attachment> _pending = [];
  Timer? _draftTimer;
  bool _showJump = false;
  String? _error;
  int? _userId;
  // Notification deep-link: the message to scroll to + flash, its key, and the
  // timer that clears the flash.
  int? _highlightId;
  final GlobalKey _highlightKey = GlobalKey();
  Timer? _highlightTimer;
  PulseRealtime? _realtime;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;

  // Typing indicators (userId -> expiry).
  final Map<int, DateTime> _typingUsers = {};
  DateTime? _lastTypingPing;
  Timer? _typingCleanup;

  // @-mention autocomplete
  List<PulseMember> _members = [];
  List<PulseMember> _mentionSuggestions = [];
  int _mentionAnchor = -1; // index of the active '@'

  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '🎉', '👀', '✅'];

  @override
  void initState() {
    super.initState();
    activeChannelId = widget.channelId;
    _loadUserId();
    _load();
    _loadDraft();
    _initRealtime();
    _loadMembers();
    _composer.addListener(_onComposerChanged);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (activeChannelId == widget.channelId) activeChannelId = null;
    _composer.removeListener(_onComposerChanged);
    _draftTimer?.cancel();
    _highlightTimer?.cancel();
    _rtSub?.cancel();
    _typingSub?.cancel();
    _typingCleanup?.cancel();
    _realtime?.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.removeListener(_onScroll);
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
    _typingSub = rt.onTyping.listen(_onTyping);
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

  Future<void> _loadDraft() async {
    try {
      final body = await ChatRepository.instance.loadDraft(widget.channelId);
      if (!mounted || body == null || body.isEmpty) return;
      if (_composer.text.isEmpty) _composer.text = body;
    } on DioException {
      // Drafts are best-effort.
    }
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final text = _composer.text;
        if (text.trim().isEmpty) {
          await ChatRepository.instance.clearDraft(widget.channelId);
        } else {
          await ChatRepository.instance.saveDraft(widget.channelId, text);
        }
      } catch (_) {}
    });
  }

  void _onLiveMessage(Map<String, dynamic> p) {
    if (!mounted) return;
    if ((p['channel_id'] as int?) != widget.channelId) return;
    if (p['parent_message_id'] != null) return; // thread reply, not the main list
    final id = p['message_id'] as int;
    if (_messages.any((m) => m.id == id)) return; // dedup (incl. our own echo)
    final body = (p['body'] ?? '') as String;
    final uid = p['user_id'] as int?;
    final msg = PulseMessage(
      id: id,
      userId: uid,
      body: body,
      bodyRendered: p['body_rendered'] as String?,
      kind: 'user',
      authorName: (p['user_name'] ?? 'Someone') as String,
      createdAt: p['created_at'] != null
          ? DateTime.tryParse(p['created_at'] as String)
          : null,
    );
    // Reconcile our own optimistic bubble (sent over HTTP, echoed over Reverb)
    // so the message doesn't briefly appear twice.
    final tmpIdx = _messages.indexWhere((m) =>
        m.sendState == MessageSendState.sending &&
        m.userId == uid &&
        m.body == body);
    if (tmpIdx != -1) {
      setState(() => _messages = [..._messages]..[tmpIdx] = msg);
      _markRead();
      return;
    }
    setState(() => _messages = [..._messages, msg]);
    _jumpToBottom();
    _markRead();
  }

  void _onTyping(Map<String, dynamic> p) {
    if (!mounted) return;
    if ((p['channel_id'] as int?) != widget.channelId) return;
    if (p['parent_message_id'] != null) return; // thread typing, not here
    final uid = p['user_id'] as int?;
    if (uid == null || uid == _userId) return;
    final exp = p['expires_at'] != null
        ? DateTime.tryParse(p['expires_at'] as String)
        : null;
    if (exp == null) return;
    setState(() => _typingUsers[uid] = exp);
    _scheduleTypingCleanup();
  }

  void _scheduleTypingCleanup() {
    _typingCleanup ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final before = _typingUsers.length;
      _typingUsers.removeWhere((_, exp) => exp.isBefore(now));
      if (mounted && _typingUsers.length != before) setState(() {});
      if (_typingUsers.isEmpty) {
        _typingCleanup?.cancel();
        _typingCleanup = null;
      }
    });
  }

  Future<void> _pingTyping() async {
    if (_composer.text.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingPing != null &&
        now.difference(_lastTypingPing!).inSeconds < 3) {
      return;
    }
    _lastTypingPing = now;
    try {
      await ChatRepository.instance.sendTyping(widget.channelId);
    } on DioException {
      // best-effort
    }
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
      _scrollToHighlight();
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
    final ids = _pending
        .where((a) => a.status == _UploadStatus.ready && a.id != null)
        .map((a) => a.id!)
        .toList();
    if (text.isEmpty && ids.isEmpty) return;
    // Show the message right away with a "sending" state; the composer clears
    // immediately so it feels instant instead of waiting on the round-trip.
    final tempId = _nextTempId--;
    final optimistic = PulseMessage(
      id: tempId,
      userId: _userId,
      body: text.isNotEmpty
          ? text
          : '📎 ${ids.length} attachment${ids.length == 1 ? '' : 's'}',
      kind: 'user',
      authorName: 'You',
      createdAt: DateTime.now(),
      sendState: MessageSendState.sending,
    );
    setState(() {
      _messages = [..._messages, optimistic];
      _composer.clear();
      _pending.clear();
    });
    _clearMentions();
    _draftTimer?.cancel();
    unawaited(
        ChatRepository.instance.clearDraft(widget.channelId).catchError((_) {}));
    _jumpToBottom();
    await _deliver(tempId, text, ids);
  }

  Future<void> _deliver(int tempId, String text, List<int> attachmentIds) async {
    try {
      final msg = widget.isDm
          ? await ChatRepository.instance
              .sendDm(widget.channelId, text, attachmentIds: attachmentIds)
          : await ChatRepository.instance
              .send(widget.channelId, text, attachmentIds: attachmentIds);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (_messages.any((m) => m.id == msg.id)) {
          // The Reverb echo already placed the real message; drop the stub.
          if (idx != -1) _messages = [..._messages]..removeAt(idx);
        } else if (idx != -1) {
          _messages = [..._messages]..[idx] = msg;
        } else {
          _messages = [..._messages, msg];
        }
      });
      _jumpToBottom();
    } on DioException {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          final updated = [..._messages];
          updated[idx] =
              updated[idx].copyWith(sendState: MessageSendState.failed);
          _messages = updated;
        }
      });
    }
  }

  Future<void> _retry(PulseMessage failed) async {
    final idx = _messages.indexWhere((m) => m.id == failed.id);
    if (idx == -1) return;
    setState(() {
      final updated = [..._messages];
      updated[idx] = updated[idx].copyWith(sendState: MessageSendState.sending);
      _messages = updated;
    });
    await _deliver(failed.id, failed.body, const []);
  }

  // ---- Attachments ----

  Future<void> _pickFiles() async {
    final List<XFile> files;
    try {
      files = await openFiles();
    } catch (_) {
      return;
    }
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final att = _Attachment(name: f.name);
      setState(() => _pending.add(att));
      try {
        final id = await ChatRepository.instance.uploadAttachment(
          channelId: widget.channelId,
          filename: f.name,
          mimeType: _mimeFromName(f.name),
          bytes: bytes,
        );
        if (!mounted) return;
        setState(() {
          att.id = id;
          att.status = _UploadStatus.ready;
        });
      } on DioException catch (e) {
        if (!mounted) return;
        setState(() => att.status = _UploadStatus.error);
        final msg = e.response?.statusCode == 402
            ? "File uploads aren't included in your plan."
            : 'Upload failed: ${f.name}';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _removePending(_Attachment a) {
    setState(() => _pending.remove(a));
  }

  String _mimeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'zip': 'application/zip',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  // ---- Reactions + message actions ----

  /// WhatsApp-style context menu anchored at [position] (the click/long-press
  /// point): a quick-react row on top, then the actions.
  Future<void> _showMessageActions(PulseMessage m, Offset position) async {
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
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        _menuItem('reply', Icons.forum_outlined, 'Reply in thread'),
        _menuItem('pin', m.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            m.isPinned ? 'Unpin message' : 'Pin message'),
        _menuItem('save', m.isSaved ? Icons.bookmark : Icons.bookmark_border,
            m.isSaved ? 'Remove from saved' : 'Save message'),
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
    switch (result) {
      case 'reply':
        _openThread(m);
      case 'pin':
        _togglePin(m);
      case 'save':
        _toggleSave(m);
      case 'forward':
        _forwardMessage(m);
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
    _pingTyping();
    _scheduleDraftSave();
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

  /// Opened from a notification: scroll the target message into view and flash
  /// it briefly (like the web app), then clear the flash. The list has variable
  /// row heights, so we first jump to roughly the message's position to force
  /// its tile to build, then fine-tune with Scrollable.ensureVisible.
  void _scrollToHighlight() {
    final id = widget.highlightMessageId;
    if (id == null) return;
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    setState(() => _highlightId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_scroll.hasClients && _messages.length > 1) {
        final frac = idx / (_messages.length - 1);
        _scroll.jumpTo(_scroll.position.maxScrollExtent * frac.clamp(0.0, 1.0));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (!mounted) return;
      final ctx = _highlightKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _highlightId = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final leadingIcon = widget.isDm
        ? (widget.kind == 'group_dm' ? Icons.group_outlined : Icons.person_outline)
        : (widget.kind == 'private' ? Icons.lock_outline : Icons.tag);
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: widget.isDm ? null : _openDetails,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(leadingIcon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(widget.channelName,
                      overflow: TextOverflow.ellipsis)),
              if (!widget.isDm) const Icon(Icons.expand_more, size: 18),
            ],
          ),
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
          Expanded(
            child: Stack(
              children: [
                _buildList(),
                if (_showJump)
                  Positioned(right: 14, bottom: 12, child: _jumpButton()),
              ],
            ),
          ),
          _buildTypingIndicator(),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final next = i < _messages.length - 1 ? _messages[i + 1] : null;
        final showDay = _showDaySeparator(prev, m);
        final groupStart = showDay || _isGroupStart(prev, m);
        final groupEnd = _isGroupEnd(m, next);
        final showTime = _showTime(m, next);
        final tile = _messageTile(m,
            groupStart: groupStart, groupEnd: groupEnd, showTime: showTime);
        if (!showDay) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_daySeparator(m.createdAt), tile],
        );
      },
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final show =
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 400;
    if (show != _showJump) setState(() => _showJump = show);
  }

  void _animateToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _jumpButton() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _animateToBottom,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(Icons.keyboard_arrow_down, color: cs.primary),
        ),
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  bool _sameMinute(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year &&
        la.month == lb.month &&
        la.day == lb.day &&
        la.hour == lb.hour &&
        la.minute == lb.minute;
  }

  bool _showDaySeparator(PulseMessage? prev, PulseMessage m) {
    if (m.createdAt == null) return false;
    if (prev == null || prev.createdAt == null) return true;
    return !_sameDay(prev.createdAt, m.createdAt);
  }

  // Same-author grouping: a run breaks on a different author, a new day, or a
  // gap over 60 min (a long pause starts a fresh avatar) — mirrors the web app.
  static const int _groupGapMinutes = 60;

  bool _isGroupStart(PulseMessage? prev, PulseMessage m) {
    if (prev == null) return true;
    if (prev.userId != m.userId) return true;
    if (prev.createdAt == null || m.createdAt == null) return true;
    if (!_sameDay(prev.createdAt, m.createdAt)) return true;
    return m.createdAt!.difference(prev.createdAt!).inMinutes.abs() >
        _groupGapMinutes;
  }

  bool _isGroupEnd(PulseMessage m, PulseMessage? next) {
    if (next == null) return true;
    if (next.userId != m.userId) return true;
    if (m.createdAt == null || next.createdAt == null) return true;
    if (!_sameDay(m.createdAt, next.createdAt)) return true;
    return next.createdAt!.difference(m.createdAt!).inMinutes.abs() >
        _groupGapMinutes;
  }

  // Show one timestamp per same-author, same-minute burst (under the last one).
  bool _showTime(PulseMessage m, PulseMessage? next) {
    if (next == null) return true;
    if (next.userId == m.userId && _sameMinute(m.createdAt, next.createdAt)) {
      return false;
    }
    return true;
  }

  Widget _daySeparator(DateTime? dt) {
    if (dt == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: cs.outlineVariant)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(_dayLabel(dt),
                style: TextStyle(
                    color: cs.outline,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Container(height: 1, color: cs.outlineVariant)),
        ],
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    final l = dt.toLocal();
    final now = DateTime.now();
    final day = DateTime(l.year, l.month, l.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'
    ];
    if (diff > 1 && diff < 7) return weekdays[l.weekday - 1];
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mon = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final base = '${wd[l.weekday - 1]}, ${mon[l.month - 1]} ${l.day}';
    return l.year == now.year ? base : '$base ${l.year}';
  }

  // Avatar gradients — deterministic per user id (mirrors the web palette).
  static const List<List<Color>> _avatarPalette = [
    [Color(0xFFFDA4AF), Color(0xFFF43F5E)], // rose
    [Color(0xFFFCD34D), Color(0xFFF59E0B)], // amber
    [Color(0xFF6EE7B7), Color(0xFF10B981)], // emerald
    [Color(0xFF7DD3FC), Color(0xFF0EA5E9)], // sky
    [Color(0xFFA5B4FC), Color(0xFF6366F1)], // indigo
    [Color(0xFFD8B4FE), Color(0xFFA855F7)], // purple
    [Color(0xFF5EEAD4), Color(0xFF14B8A6)], // teal
    [Color(0xFFFDBA74), Color(0xFFF97316)], // orange
  ];
  static const List<Color> _ownAvatar = [Color(0xFF94A3B8), Color(0xFF64748B)];

  Widget _avatar(PulseMessage m, bool isOwn) {
    final pair = isOwn
        ? _ownAvatar
        : _avatarPalette[(m.userId ?? 0).abs() % _avatarPalette.length];
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
      ),
      alignment: Alignment.center,
      child: Text(_initials(m.authorName),
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _messageTile(PulseMessage m,
      {required bool groupStart,
      required bool groupEnd,
      required bool showTime}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwn = _userId != null && m.userId == _userId;
    const brand = Color(0xFFF97316);
    final highlighted = _highlightId == m.id;
    final bubbleColor =
        isOwn ? brand : (isDark ? const Color(0xFF1B2438) : Colors.white);
    final textColor = isOwn ? Colors.white : cs.onSurface;

    final bubble = GestureDetector(
      onLongPressStart: m.sendState == MessageSendState.sent
          ? (d) => _showMessageActions(m, d.globalPosition)
          : null,
      // Right-click opens the action menu at the pointer (desktop).
      onSecondaryTapDown: m.sendState == MessageSendState.sent
          ? (d) => _showMessageActions(m, d.globalPosition)
          : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: m.sendState == MessageSendState.sending ? 0.7 : 1,
        child: Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: _bubbleRadius(isOwn, groupStart, groupEnd),
            border: isOwn
                ? null
                : Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                  blurRadius: 3,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: _body(m.body, color: textColor),
        ),
      ),
    );

    final col = Column(
      crossAxisAlignment:
          isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (groupStart && !isOwn)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4, top: 2),
            child: Text(m.authorName,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: cs.onSurface)),
          ),
        bubble,
        AttachmentView(attachments: m.attachments),
        if (isOwn && m.sendState == MessageSendState.sending)
          _statusLabel('Sending…', cs.outline),
        if (isOwn && m.sendState == MessageSendState.failed)
          InkWell(
            onTap: () => _retry(m),
            child: _statusLabel('Not sent — tap to retry', cs.error,
                icon: Icons.error_outline),
          ),
        if (showTime &&
            m.createdAt != null &&
            m.sendState == MessageSendState.sent)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_time(m.createdAt!),
                    style: TextStyle(color: cs.outline, fontSize: 10)),
                if (m.editedAt != null) ...[
                  const SizedBox(width: 5),
                  Text('(edited)',
                      style: TextStyle(
                          color: cs.outline,
                          fontSize: 10,
                          fontStyle: FontStyle.italic)),
                ],
                if (m.isPinned) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.push_pin, size: 11, color: cs.outline),
                ],
              ],
            ),
          ),
        _reactionChips(m),
        _replyCountRow(m),
      ],
    );

    final avatarOrSpacer =
        groupStart ? _avatar(m, isOwn) : const SizedBox(width: 32);

    final rowChildren = isOwn
        ? [Expanded(child: col), const SizedBox(width: 8), avatarOrSpacer]
        : [avatarOrSpacer, const SizedBox(width: 8), Expanded(child: col)];

    final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren);
    // The hover toolbar wraps the whole row so it paints above the avatar and
    // isn't clipped by the bubble — desktop only; touch never hovers.
    final content = m.sendState == MessageSendState.sent
        ? HoverActions(
            isOwn: isOwn,
            emojis: _quickEmojis,
            onReactEmoji: (e) => _toggleReaction(m, e),
            onReply: () => _openThread(m),
            onMore: (pos) => _showMessageActions(m, pos),
            child: row,
          )
        : row;
    return AnimatedContainer(
      key: highlighted ? _highlightKey : null,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      color: highlighted ? brand.withValues(alpha: 0.16) : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(
            left: 10,
            right: 10,
            top: groupStart ? 8 : 1.5,
            bottom: groupEnd ? 6 : 1.5),
        child: content,
      ),
    );
  }

  BorderRadius _bubbleRadius(bool isOwn, bool groupStart, bool groupEnd) {
    const r = Radius.circular(16);
    const tight = Radius.circular(5);
    final topInner = groupStart ? r : tight;
    final bottomInner = groupEnd ? r : tight;
    if (isOwn) {
      return BorderRadius.only(
          topLeft: r,
          bottomLeft: r,
          topRight: topInner,
          bottomRight: bottomInner);
    }
    return BorderRadius.only(
        topRight: r,
        bottomRight: r,
        topLeft: topInner,
        bottomLeft: bottomInner);
  }

  Widget _statusLabel(String text, Color color, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 10)),
        ],
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

  void _forwardMessage(PulseMessage m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ForwardScreen(messageId: m.id, preview: m.body),
    ));
  }

  void _openPins() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PinnedScreen(
        channelId: widget.channelId,
        channelName: widget.channelName,
      ),
    ));
  }

  void _openDetails() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChannelDetailsScreen(
            channelId: widget.channelId,
            channelName: widget.channelName,
            kind: widget.kind,
          ),
        ))
        .then((_) => _load());
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

  /// Renders the message body with inline Markdown + @mentions. [color] sets the
  /// base text colour (white on own orange bubbles; null keeps the themed ink).
  Widget _body(String body, {Color? color}) =>
      messageBody(context, body, color: color);

  Widget _buildTypingIndicator() {
    if (_typingUsers.isEmpty) return const SizedBox.shrink();
    final names = _typingUsers.keys.map((uid) {
      final match = _members.where((x) => x.userId == uid);
      final name = match.isNotEmpty ? match.first.name : 'Someone';
      return name.split(' ').first;
    }).toList();
    final String text;
    if (names.length == 1) {
      text = '${names.first} is typing…';
    } else if (names.length == 2) {
      text = '${names[0]} and ${names[1]} are typing…';
    } else {
      text = 'Several people are typing…';
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                color: cs.outline, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
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

  Widget _buildPendingAttachments() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in _pending)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.status == _UploadStatus.uploading)
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else if (a.status == _UploadStatus.error)
                    Icon(Icons.error_outline, size: 14, color: cs.error)
                  else
                    Icon(Icons.check_circle, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  InkWell(
                    onTap: () => _removePending(a),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: cs.outline),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pending.isNotEmpty) _buildPendingAttachments(),
            ComposerToolbar(controller: _composer, focusNode: _composerFocus),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Attach a file',
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    focusNode: _composerFocus,
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
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
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

enum _UploadStatus { uploading, ready, error }

/// A file being uploaded from the composer before it's attached to a message.
class _Attachment {
  _Attachment({required this.name});
  final String name;
  int? id;
  _UploadStatus status = _UploadStatus.uploading;
}
