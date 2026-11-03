import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// Read-only list of a conversation's pinned messages.
class PinnedScreen extends StatefulWidget {
  const PinnedScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  final int channelId;
  final String channelName;

  @override
  State<PinnedScreen> createState() => _PinnedScreenState();
}

class _PinnedScreenState extends State<PinnedScreen> {
  List<PulseMessage>? _pins;
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
      final p = await ChatRepository.instance.pins(widget.channelId);
      if (!mounted) return;
      setState(() {
        _pins = p;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load pinned messages.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pinned · ${widget.channelName}')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final list = _pins ?? [];
    if (list.isEmpty) return _centered('No pinned messages yet.');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = list[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.push_pin, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(m.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  if (m.createdAt != null)
                    Text(formatMessageTimestamp(m.createdAt!),
                        style: TextStyle(color: cs.outline, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),
              Text(m.body),
            ],
          ),
        );
      },
    );
  }

  Widget _centered(String msg) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(child: Text(msg, style: TextStyle(color: cs.outline))),
      ],
    );
  }
}
