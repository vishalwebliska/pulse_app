import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'contacts_repository.dart';
import 'device_contacts.dart';

enum _InviteState { idle, inviting, invited, alreadyMember, self }

/// "Add contacts" — the Skype-style find-and-invite surface. Look up any email
/// (or sync device contacts) to see who's already on Flaxxa, then invite the
/// rest. People already in your workspace are messaged from "Find people".
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _email = TextEditingController();
  final List<ContactLookup> _results = [];
  final Map<String, _InviteState> _invites = {};
  bool _loading = false;
  String? _message;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _findOne() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final res = await ContactsRepository.instance.lookup([email]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _merge(res);
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = "Couldn't check that email.";
      });
    }
  }

  Future<void> _syncDevice() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final emails = await readDeviceContactEmails();
      if (emails.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _message = 'No email addresses found in your contacts.';
        });
        return;
      }
      final found = <ContactLookup>[];
      for (var i = 0; i < emails.length; i += 500) {
        final end = (i + 500) < emails.length ? i + 500 : emails.length;
        found.addAll(await ContactsRepository.instance.lookup(emails.sublist(i, end)));
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _merge(found);
      });
    } on StateError {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Contacts permission was denied.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = "Couldn't read your contacts.";
      });
    }
  }

  void _merge(List<ContactLookup> incoming) {
    final seen = {for (final r in _results) r.email};
    for (final r in incoming) {
      if (seen.add(r.email)) _results.add(r);
    }
    _results.sort((a, b) {
      if (a.registered != b.registered) return a.registered ? -1 : 1;
      return a.email.compareTo(b.email);
    });
  }

  Future<void> _invite(ContactLookup c) async {
    setState(() => _invites[c.email] = _InviteState.inviting);
    try {
      final outcome = await ContactsRepository.instance.invite(c.email);
      if (!mounted) return;
      setState(() {
        _invites[c.email] = switch (outcome) {
          InviteOutcome.invited => _InviteState.invited,
          InviteOutcome.alreadyMember => _InviteState.alreadyMember,
          InviteOutcome.self => _InviteState.self,
        };
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _invites[c.email] = _InviteState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't send the invite. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Add contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _findOne(),
                    decoration: const InputDecoration(
                      labelText: 'Invite by email',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _findOne,
                    child: const Text('Find'),
                  ),
                ),
              ],
            ),
          ),
          if (deviceContactsSupported)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  onPressed: _loading ? null : _syncDevice,
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Sync device contacts'),
                ),
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_message!, style: TextStyle(color: cs.outline)),
              ),
            ),
          const Divider(height: 1),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _resultsList(cs)),
        ],
      ),
    );
  }

  Widget _resultsList(ColorScheme cs) {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Look up an email to invite someone to Pulse.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _row(_results[i], cs),
    );
  }

  Widget _row(ContactLookup c, ColorScheme cs) {
    final state = _invites[c.email] ?? _InviteState.idle;
    final title = c.registered && (c.name?.isNotEmpty ?? false) ? c.name! : c.email;
    final subtitle =
        c.registered ? c.email : 'Not on Pulse yet — invite to join';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.registered
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surfaceContainerHighest,
        child: Icon(
          c.registered ? Icons.person : Icons.mail_outline,
          color: c.registered ? cs.primary : cs.outline,
          size: 20,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _action(c, state),
    );
  }

  Widget _action(ContactLookup c, _InviteState state) {
    switch (state) {
      case _InviteState.inviting:
        return const SizedBox(
          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
      case _InviteState.invited:
        return const _DoneChip(icon: Icons.check, label: 'Invited');
      case _InviteState.alreadyMember:
        return const _DoneChip(icon: Icons.check_circle_outline, label: 'Added');
      case _InviteState.self:
        return const _DoneChip(icon: Icons.person, label: 'You');
      case _InviteState.idle:
        return FilledButton.tonal(
          onPressed: () => _invite(c),
          child: Text(c.registered ? 'Connect' : 'Invite'),
        );
    }
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cs.outline),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: cs.outline, fontSize: 13)),
      ],
    );
  }
}
