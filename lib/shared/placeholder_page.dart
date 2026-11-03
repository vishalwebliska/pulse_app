import 'package:flutter/material.dart';

/// Simple centered placeholder used by the pillar tabs until each is built out.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.note,
  });

  final String title;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: cs.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
