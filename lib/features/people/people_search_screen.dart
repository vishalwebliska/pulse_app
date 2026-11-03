import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../chat/channel_screen.dart';
import '../chat/chat_models.dart';
import '../chat/chat_repository.dart';

/// "Find each other": search the workspace directory and tap a person to open
/// (or create) a 1:1 direct message with them.
class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({super.key});

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<PulseMember> _results = [];
  bool _loading = true;
  bool _starting = false;
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

  void _onChanged(String value) {
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

  Future<void> _startDm(PulseMember m) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final channel = await ChatRepository.instance.createDm([m.userId]);
      if (!mounted) return;
      setState(() => _starting = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: channel.id,
            channelName: m.name,
            kind: channel.kind,
            isDm: true,
          ),
        ),
      );
    } on DioException {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't start the chat.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find people'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_starting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) {
      return Center(
        child: Text('No people found.', style: TextStyle(color: cs.outline)),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _results[i];
        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(child: Text(_initials(m.name))),
              if (m.online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(m.name),
          subtitle: Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: m.status == 'invited'
              ? Chip(
                  label: const Text('invited'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: cs.outlineVariant),
                )
              : const Icon(Icons.chat_bubble_outline),
          onTap: () => _startDm(m),
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
