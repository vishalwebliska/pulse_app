import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/google_connect.dart';

/// Shared handling for the "Start a meeting" action, used by both a
/// conversation's app bar and the Meetings tab.

/// Open a minted Google Meet link in the browser / Meet app.
Future<void> openMeetingLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    try {
      await launchUrl(uri);
    } catch (_) {
      // Nothing can open the link; the meeting message still carries it.
    }
  }
}

/// Pull the backend's user-facing error out of a failed meeting response.
String meetingErrorMessage(Object? data) =>
    (data is Map && data['error'] is String)
        ? data['error'] as String
        : 'Could not start the meeting. Please try again.';

/// Show the right feedback for a failed meeting: on 409 (Google not linked) a
/// "Connect Google" dialog that runs the in-app connect flow and, once linked,
/// calls [onConnected] so the caller can retry the meeting; otherwise a snackbar.
Future<void> showMeetingError(
  BuildContext context, {
  required int? statusCode,
  required String message,
  Future<void> Function()? onConnected,
}) async {
  if (statusCode != 409) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return;
  }

  final wantsConnect = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.videocam_outlined),
      title: const Text('Connect Google to meet'),
      content: Text(
        '$message\n\nMeetings use Google Meet. Connect your Google account to start one.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Connect Google'),
        ),
      ],
    ),
  );

  if (wantsConnect != true || !context.mounted) return;

  final connected = await GoogleConnect.connect(context);
  if (connected && onConnected != null) {
    await onConnected();
  }
}
