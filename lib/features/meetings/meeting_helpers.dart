import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Show the right feedback for a failed meeting: a "connect Google" dialog on
/// 409 (the user — or the workspace — hasn't linked Google yet, which is done
/// on the web), otherwise a plain snackbar.
void showMeetingError(
  BuildContext context, {
  required int? statusCode,
  required String message,
}) {
  if (statusCode == 409) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.videocam_outlined),
        title: const Text('Connect Google to meet'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
