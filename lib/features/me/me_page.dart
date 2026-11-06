import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/google_connect.dart';
import '../auth/auth_controller.dart';
import '../chat/reminders_screen.dart';
import '../chat/saved_screen.dart';
import '../chat/todos_screen.dart';
import '../contacts/contacts_screen.dart';
import '../people/people_search_screen.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final ws = auth.currentWorkspace;

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                const CircleAvatar(
                    radius: 32, child: Icon(Icons.person, size: 32)),
                const SizedBox(height: 12),
                Text(
                  ws != null
                      ? ws.name
                      : (auth.tenantId == null
                          ? 'No workspace selected'
                          : 'Workspace'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (auth.workspaces.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${auth.workspaces.length} workspaces · switch from the Chat tab',
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Find people'),
            subtitle: const Text('Message someone in your workspace'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PeopleSearchScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Add contacts'),
            subtitle: const Text('Invite people by email or from your contacts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Connect Google'),
            subtitle: const Text('Needed to start Meet video calls'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ok = await GoogleConnect.connect(context);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Google connected — you can start meetings now.'
                    : 'Google was not connected.'),
              ));
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Saved messages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Reminders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Todos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TodosScreen())),
          ),
          const Divider(height: 1),
          const SizedBox(height: 28),
          Center(
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}
