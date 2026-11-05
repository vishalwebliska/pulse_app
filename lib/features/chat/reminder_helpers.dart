import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'chat_repository.dart';

/// The presets the backend accepts, in display order.
const Map<String, String> kReminderPresets = {
  'in_20_min': 'In 20 minutes',
  'in_1_hour': 'In 1 hour',
  'in_3_hours': 'In 3 hours',
  'tomorrow': 'Tomorrow',
  'next_week': 'Next week',
};

/// Show the "Remind me about this" preset sheet and set the reminder on the
/// backend. Shared by the conversation and thread message menus.
Future<void> remindAboutMessage(BuildContext context, int messageId) async {
  final preset = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Remind me about this',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
          const Divider(height: 1),
          for (final e in kReminderPresets.entries)
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(e.value),
              onTap: () => Navigator.of(ctx).pop(e.key),
            ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (preset == null || !context.mounted) return;
  try {
    await ChatRepository.instance.remindMe(messageId, preset);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder set · ${kReminderPresets[preset]!}')),
    );
  } on DioException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't set the reminder.")),
    );
  }
}
