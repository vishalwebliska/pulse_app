import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

const Color _brand = Color(0xFFF97316);

/// Workspace todos — assignable tasks. List with filters, create (with an
/// optional assignee), tick off, and delete. Backed by `/pulse/todos`.
class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  static const _filters = {
    'mine': 'Mine',
    'assigned': 'Assigned to me',
    'created': 'Created by me',
    'all': 'All',
  };

  String _filter = 'mine';
  List<PulseTodo>? _items;
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
      final items = await ChatRepository.instance.todos(filter: _filter);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? "Todos aren't enabled for this workspace."
            : "Couldn't load todos.";
      });
    }
  }

  Future<void> _toggleDone(PulseTodo t) async {
    // Optimistic flip.
    setState(() {
      _items = _items
          ?.map((x) => x.id == t.id
              ? PulseTodo(
                  id: x.id,
                  title: x.title,
                  isDone: !x.isDone,
                  description: x.description,
                  creatorName: x.creatorName,
                  assigneeName: x.assigneeName,
                  assignedToUserId: x.assignedToUserId,
                )
              : x)
          .toList();
    });
    try {
      await ChatRepository.instance.updateTodo(t.id, isDone: !t.isDone);
    } on DioException {
      if (!mounted) return;
      _load(); // reconcile
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update the todo.")));
    }
  }

  Future<void> _delete(PulseTodo t) async {
    setState(() => _items = _items?.where((x) => x.id != t.id).toList());
    try {
      await ChatRepository.instance.deleteTodo(t.id);
    } on DioException {
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete the todo.")));
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateTodoSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        onPressed: _create,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New todo', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          _filterBar(),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final e in _filters.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _filter == e.key,
                onSelected: (_) {
                  if (_filter != e.key) {
                    setState(() => _filter = e.key);
                    _load();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(_error!);
    final list = _items ?? [];
    if (list.isEmpty) return _centered('No todos here yet.');
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = list[i];
        return ListTile(
          leading: Checkbox(
            value: t.isDone,
            activeColor: _brand,
            onChanged: (_) => _toggleDone(t),
          ),
          title: Text(
            t.title,
            style: TextStyle(
              decoration: t.isDone ? TextDecoration.lineThrough : null,
              color: t.isDone ? cs.outline : cs.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: _subtitle(t, cs),
          trailing: IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: cs.outline),
            onPressed: () => _delete(t),
          ),
        );
      },
    );
  }

  Widget? _subtitle(PulseTodo t, ColorScheme cs) {
    final parts = <Widget>[];
    if (t.description != null && t.description!.isNotEmpty) {
      parts.add(Text(t.description!,
          maxLines: 2, overflow: TextOverflow.ellipsis));
    }
    if (t.assigneeName != null && t.assigneeName!.isNotEmpty) {
      parts.add(Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 13, color: cs.outline),
            const SizedBox(width: 3),
            Text(t.assigneeName!,
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
      ));
    }
    if (parts.isEmpty) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts);
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

/// Create-todo sheet: title (required), description, and an optional assignee
/// chosen from the workspace directory. Pops `true` when a todo was created.
class _CreateTodoSheet extends StatefulWidget {
  const _CreateTodoSheet();

  @override
  State<_CreateTodoSheet> createState() => _CreateTodoSheetState();
}

class _CreateTodoSheetState extends State<_CreateTodoSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  PulseMember? _assignee;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickAssignee() async {
    final picked = await showModalBottomSheet<PulseMember>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AssigneePicker(),
    );
    if (picked != null) setState(() => _assignee = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ChatRepository.instance.createTodo(
        title: title,
        description: _desc.text.trim(),
        assignedToUserId: _assignee?.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.response?.statusCode == 422
          ? 'Assignee must be a workspace member.'
          : "Couldn't create the todo.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New todo',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickAssignee,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: cs.outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _assignee == null
                          ? 'Assign to (optional)'
                          : 'Assigned to ${_assignee!.name}',
                      style: TextStyle(
                          color: _assignee == null ? cs.outline : cs.onSurface),
                    ),
                  ),
                  if (_assignee != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _assignee = null),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create todo'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A searchable workspace-member picker used to assign a todo.
class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker();

  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  final _q = TextEditingController();
  List<PulseMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final people = await ChatRepository.instance.directory(q: q);
      if (!mounted) return;
      setState(() {
        _members = people;
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _search,
                decoration: const InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, i) {
                        final m = _members[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text(_initials(m.name))),
                          title: Text(m.name),
                          subtitle: Text(m.email,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(m),
                        );
                      },
                    ),
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
}
