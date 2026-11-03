import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Create a named group (a private channel) and pick who's in it. On success,
/// opens the new group's conversation.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;

  List<PulseMember> _results = [];
  final Map<int, PulseMember> _selected = {};
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query('');
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(value));
  }

  Future<void> _query(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await ChatRepository.instance.directory(q: q.trim());
      if (!mounted) return;
      setState(() {
        _results = people;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load people.";
      });
    }
  }

  bool get _canCreate => _name.text.trim().isNotEmpty && !_creating;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final channel = await ChatRepository.instance.createGroupChannel(
        name: name,
        userIds: _selected.keys.toList(),
      );
      if (!mounted) return;
      setState(() => _creating = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: channel.id,
            channelName: channel.name,
            kind: channel.kind,
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final msg = e.response?.statusCode == 422
          ? "That name won't work, or you've hit your channel limit."
          : "Couldn't create the group.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _toggle(PulseMember m) {
    setState(() {
      if (_selected.containsKey(m.userId)) {
        _selected.remove(m.userId);
      } else {
        _selected[m.userId] = m;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _canCreate ? _create : null,
            child: _creating
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Group name',
                prefixIcon: Icon(Icons.group_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_selected.isNotEmpty) _buildSelectedChips(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Add people by name or email',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildSelectedChips() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 6,
          children: _selected.values
              .map((m) => InputChip(
                    label: Text(m.name),
                    onDeleted: () => _toggle(m),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) {
      return Center(
        child: Text('No people found.', style: TextStyle(color: cs.outline)),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final m = _results[i];
        final checked = _selected.containsKey(m.userId);
        return CheckboxListTile(
          value: checked,
          onChanged: (_) => _toggle(m),
          secondary: CircleAvatar(child: Text(_initials(m.name))),
          title: Text(m.name),
          subtitle: Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
