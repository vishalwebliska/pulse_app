import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'add_members_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Channel details: topic/purpose, member list, add people (private), leave.
class ChannelDetailsScreen extends StatefulWidget {
  const ChannelDetailsScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.kind,
  });

  final int channelId;
  final String channelName;
  final String kind;

  @override
  State<ChannelDetailsScreen> createState() => _ChannelDetailsScreenState();
}

class _ChannelDetailsScreenState extends State<ChannelDetailsScreen> {
  PulseChannel? _info;
  List<ChannelMemberRow> _members = [];
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
      final info = await ChatRepository.instance.channelInfo(widget.channelId);
      final members =
          await ChatRepository.instance.channelMembers(widget.channelId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _members = members;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load channel details.";
      });
    }
  }

  Future<void> _addPeople() async {
    final existing = _members.map((m) => m.userId).toSet();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddMembersScreen(
        channelId: widget.channelId,
        existingUserIds: existing,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave channel?'),
        content: Text(
            'You will stop receiving messages from #${widget.channelName}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatRepository.instance.leaveChannel(widget.channelId);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on DioException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't leave the channel.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.channelName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(onRefresh: _load, child: _body(cs)),
    );
  }

  Widget _body(ColorScheme cs) {
    final topic = _info?.topic;
    final isGeneral = _info?.isGeneral ?? false;
    return ListView(
      children: [
        if (topic != null && topic.isNotEmpty) ...[
          _label('TOPIC', cs),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(topic),
          ),
          const Divider(height: 1),
        ],
        _label('MEMBERS (${_members.length})', cs),
        if (widget.kind == 'private')
          ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.person_add_alt, color: cs.onPrimaryContainer),
            ),
            title: const Text('Add people'),
            onTap: _addPeople,
          ),
        ..._members.map((m) => ListTile(
              leading: CircleAvatar(child: Text(_initials(m.name))),
              title: Text(m.name),
              subtitle:
                  Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: m.role != 'member'
                  ? Chip(
                      label: Text(m.role),
                      visualDensity: VisualDensity.compact)
                  : null,
            )),
        const Divider(height: 1),
        if (!isGeneral)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _leave,
              icon: Icon(Icons.logout, color: cs.error),
              label: Text('Leave channel', style: TextStyle(color: cs.error)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: cs.error)),
            ),
          ),
      ],
    );
  }

  Widget _label(String t, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(t,
            style: TextStyle(
                color: cs.outline, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
