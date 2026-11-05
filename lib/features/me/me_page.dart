import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../chat/reminders_screen.dart';
import '../chat/saved_screen.dart';

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
