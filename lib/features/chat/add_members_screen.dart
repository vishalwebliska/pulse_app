import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// Pick workspace members to add to a channel. Already-in members are filtered.
class AddMembersScreen extends StatefulWidget {
  const AddMembersScreen({
    super.key,
    required this.channelId,
    required this.existingUserIds,
  });

  final int channelId;
  final Set<int> existingUserIds;

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<PulseMember> _results = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(v));
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
        _results = people
            .where((p) => !widget.existingUserIds.contains(p.userId))
            .toList();
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

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ChatRepository.instance
          .addChannelMembers(widget.channelId, _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pop();
    } on DioException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't add members.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add people'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_selected.isEmpty ? 'Add' : 'Add (${_selected.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search by name or email',
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

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) {
      return Center(
          child: Text('No one to add.', style: TextStyle(color: cs.outline)));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final m = _results[i];
        final checked = _selected.contains(m.userId);
        return CheckboxListTile(
          value: checked,
          onChanged: (_) => setState(() {
            if (checked) {
              _selected.remove(m.userId);
            } else {
              _selected.add(m.userId);
            }
          }),
          secondary: CircleAvatar(child: Text(_initials(m.name))),
          title: Text(m.name),
          subtitle:
              Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
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
