import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'channel_screen.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Message search. Opened globally (workspace-wide, plan-gated) from the Chat
/// tab, or scoped to one conversation (always available) from a channel's
/// search button.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.channelId, this.channelName});

  final int? channelId;
  final String? channelName;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;
  bool _searched = false;
  bool _planGated = false;
  String? _error;

  bool get _scoped => widget.channelId != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _planGated = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() {
      _loading = true;
      _error = null;
      _planGated = false;
    });
    try {
      final r = await ChatRepository.instance
          .searchMessages(q, channelId: widget.channelId);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
        _searched = true;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = [];
        if (e.response?.statusCode == 402) {
          _planGated = true;
        } else {
          _error = "Couldn't search. Try again.";
        }
      });
    }
  }

  void _open(SearchResult r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelScreen(
        channelId: r.channelId,
        channelName: r.channelName,
        kind: r.channelKind,
        isDm: r.isDm,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_scoped ? 'Search #${widget.channelName}' : 'Search messages'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _scoped
                    ? 'Search in this conversation'
                    : 'Search all your conversations',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_planGated) {
      return _notice(
        Icons.workspace_premium_outlined,
        "Workspace-wide search isn't on your plan",
        'Open a channel or DM and use its search button to find messages there.',
      );
    }
    if (_error != null) return _notice(Icons.error_outline, _error!, '');
    if (!_searched) {
      return _notice(
        Icons.search,
        'Search messages',
        _scoped
            ? 'Find messages in this conversation.'
            : 'Find messages across your conversations.',
      );
    }
    if (_results.isEmpty) {
      return _notice(Icons.search_off, 'No matches', 'Try different words.');
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          leading: CircleAvatar(
            child: Icon(r.isDm ? Icons.person_outline : Icons.tag),
          ),
          title: Text(r.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${r.authorName} · ${r.isDm ? r.channelName : '#${r.channelName}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.outline),
          ),
          onTap: () => _open(r),
        );
      },
    );
  }

  Widget _notice(IconData icon, String title, String sub) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.outline, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
