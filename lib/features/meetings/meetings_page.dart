import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../chat/channel_screen.dart';
import '../chat/chat_models.dart';
import '../chat/chat_repository.dart';
import 'meeting_helpers.dart';

const Color _brand = Color(0xFFF97316);

/// The Meetings tab. Pulse meetings are instant Google Meet calls started in a
/// conversation (the backend mints a real Meet link, posts it into the channel
/// and hands back the join URL). So this tab is a launcher: pick a conversation
/// to start a meeting in, then jump into it to see the posted join link.
class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key});

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  List<PulseChannel>? _conversations;
  bool _loading = true;
  String? _error;
  int? _startingId; // the conversation a meeting is being started in

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
      final res = await Future.wait([
        ChatRepository.instance.channels(),
        ChatRepository.instance.dms(),
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = [...res[0], ...res[1]];
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

  Future<void> _startMeeting(PulseChannel c) async {
    setState(() => _startingId = c.id);
    String? url;
    try {
      url = await ChatRepository.instance.startMeeting(c.id);
    } on DioException catch (e) {
      if (mounted) {
        showMeetingError(context,
            statusCode: e.response?.statusCode,
            message: meetingErrorMessage(e.response?.data));
      }
    } finally {
      if (mounted) setState(() => _startingId = null);
    }
    if (url == null || !mounted) return;
    await openMeetingLink(url);
    if (!mounted) return;
    // Open the conversation so the posted "started a meeting" message shows.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelScreen(
        channelId: c.id,
        channelName: c.title,
        kind: c.kind,
        isDm: c.isDm,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meetings')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 140),
        Center(child: Text(_error!, style: TextStyle(color: cs.outline))),
      ]);
    }
    final convos = _conversations ?? [];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _header(),
        if (convos.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text('No conversations to meet in yet.',
                  style: TextStyle(color: cs.outline)),
            ),
          )
        else ...[
          _sectionHeader('Start a meeting in'),
          ...convos.map(_conversationTile),
        ],
      ],
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBBF24), _brand],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Instant meetings',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 3),
                Text(
                  'Start a Google Meet in any conversation. The join link is '
                  'posted to the channel so everyone can hop in.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
            color: cs.outline,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5),
      ),
    );
  }

  Widget _conversationTile(PulseChannel c) {
    final starting = _startingId == c.id;
    final busy = _startingId != null;
    final IconData leadingIcon = c.isDm
        ? (c.isGroupDm ? Icons.group_outlined : Icons.person_outline)
        : (c.isPrivate ? Icons.lock_outline : Icons.tag);
    return ListTile(
      leading: CircleAvatar(child: Icon(leadingIcon)),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (!c.isDm && c.topic != null && c.topic!.isNotEmpty)
          ? Text(c.topic!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _brand,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: busy ? null : () => _startMeeting(c),
        icon: starting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.videocam, size: 18),
        label: const Text('Meet'),
      ),
      onTap: busy
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChannelScreen(
                  channelId: c.id,
                  channelName: c.title,
                  kind: c.kind,
                  isDm: c.isDm,
                ),
              )),
    );
  }
}
