import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final ws = auth.currentWorkspace;

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 32, child: Icon(Icons.person, size: 32)),
            const SizedBox(height: 12),
            Text(
              ws != null
                  ? ws.name
                  : (auth.tenantId == null
                      ? 'No workspace selected'
                      : 'Workspace'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (auth.workspaces.length > 1) ...[
              const SizedBox(height: 4),
              Text(
                '${auth.workspaces.length} workspaces · switch from the Chat tab',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
