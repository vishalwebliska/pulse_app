import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/channel_screen.dart';
import '../chat/chat_models.dart';
import '../chat/chat_repository.dart';
import '../chat/presence_provider.dart';
import '../contacts/contacts_screen.dart';

/// A row shown in the people search — either a workspace member (browse, empty
/// query) or a global Flaxxa user (search results).
class _PersonRow {
  const _PersonRow({
    required this.id,
    required this.name,
    required this.email,
    required this.fromWorkspace,
  });
  final int id;
  final String name;
  final String email;
  final bool fromWorkspace;
}

/// Find people: an empty box browses your workspace; typing searches **every**
/// Flaxxa user by email (suggestions) or exact phone number. Tap to DM (or, if
/// they're not in your workspace, invite them to connect).
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key});

  @override
  ConsumerState<PeopleSearchScreen> createState() =>
      _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<_PersonRow> _results = [];
  bool _loading = true;
  bool _starting = false;
  bool _global = false; // true when showing global search results
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
    _debounce = Timer(const Duration(milliseconds: 320), () => _query(value));
  }

  Future<void> _query(String raw) async {
    final q = raw.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    List<_PersonRow> mapMembers(List<PulseMember> m) => m
        .map((x) => _PersonRow(
            id: x.userId, name: x.name, email: x.email, fromWorkspace: true))
        .toList();
    try {
      List<_PersonRow> rows;
      bool global;
      if (q.isEmpty) {
        // Browse workspace members.
        rows = mapMembers(await ChatRepository.instance.directory());
        global = false;
      } else {
        try {
          // Global Flaxxa search (email prefix / exact phone).
          final users = await ChatRepository.instance.searchFlaxxaUsers(q);
          rows = users
              .map((u) => _PersonRow(
                  id: u.id,
                  name: u.name,
                  email: u.email,
                  fromWorkspace: false))
              .toList();
          global = true;
        } on DioException catch (e) {
          // Global endpoint not deployed yet → fall back to workspace search so
          // people search still works until the backend ships.
          if (e.response?.statusCode == 404) {
            rows = mapMembers(await ChatRepository.instance.directory(q: q));
            global = false;
          } else {
            rethrow;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _results = rows;
        _global = global;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search right now.";
      });
    }
  }

  Future<void> _tap(_PersonRow p) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final channel = await ChatRepository.instance.createDm([p.id]);
      if (!mounted) return;
      setState(() => _starting = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: channel.id,
            channelName: p.name,
            kind: channel.kind,
            isDm: true,
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      // Can't DM someone who isn't in your workspace — offer to invite them.
      if (e.response?.statusCode == 422) {
        _offerInvite(p);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start the chat.")),
        );
      }
    }
  }

  void _offerInvite(_PersonRow p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.person_add_alt_1_outlined),
        title: Text('Invite ${p.name}?'),
        content: Text(
          '${p.email} isn\'t in your workspace yet. Invite them to connect and '
          'chat on Flaxxa Pulse.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _invite(p.email);
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }

  Future<void> _invite(String email) async {
    try {
      await ChatRepository.instance.inviteContact(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invite sent to $email')));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.statusCode == 409
          ? 'They\'re already in your workspace.'
          : "Couldn't send the invite.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find people'),
        actions: [
          IconButton(
            tooltip: 'Add contacts',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Search anyone by name, email, or phone',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
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
    final online = ref.watch(presenceProvider);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _global
                ? 'No one found. Try a full email, or an exact phone number.'
                : 'No people in your workspace yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) return _hintHeader(cs);
        final p = _results[i - 1];
        final isOnline = online.contains(p.id);
        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(child: Text(_initials(p.name))),
              if (isOnline)
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
          title: Text(p.name),
          subtitle: Text(p.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(
            p.fromWorkspace ? Icons.chat_bubble_outline : Icons.person_add_alt,
            color: cs.outline,
          ),
          onTap: () => _tap(p),
        );
      },
    );
  }

  Widget _hintHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(
        _global
            ? 'ANYONE ON FLAXXA'
            : 'IN YOUR WORKSPACE',
        style: TextStyle(
            color: cs.outline,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
