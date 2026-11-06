import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Connects the signed-in user's Google account (for Meet links) using the
/// existing web OAuth flow opened in an in-app browser.
///
/// The backend (`POST /auth/mobile/google/connect`) returns a consent URL whose
/// `state` is bound to this user; we open it, the user consents, Google hits the
/// public callback which stores the connection and then bounces back into the app
/// via the `flaxxapulse://` deep link. We also poll `.../google/status` as a
/// fallback on platforms where the deep link doesn't fire (e.g. Windows).
class GoogleConnect {
  GoogleConnect._();

  /// Custom scheme the backend redirects to once Google is linked. Registered
  /// per platform (Android intent-filter, iOS/macOS CFBundleURLTypes).
  static const _appReturn = 'flaxxapulse://google';

  static Future<bool> isConnected() async {
    try {
      final res =
          await ApiClient.instance.dio.get('/auth/mobile/google/status');
      final data =
          (res.data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      return data['connected'] == true;
    } on DioException {
      return false;
    }
  }

  /// Runs the full connect flow with UI feedback. Returns true once connected.
  static Future<bool> connect(BuildContext context) async {
    String? url;
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/mobile/google/connect',
        data: {'app_return': _appReturn},
      );
      url = ((res.data['data'] as Map?)?.cast<String, dynamic>() ??
          const {})['redirect_url'] as String?;
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = (body is Map && body['message'] is String)
          ? body['message'] as String
          : "Couldn't start Google sign-in. Please try again later.";
      if (context.mounted) _toast(context, msg);
      return false;
    }
    if (url == null || url.isEmpty) {
      if (context.mounted) {
        _toast(context, "Google isn't available right now.");
      }
      return false;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (context.mounted) _toast(context, "Couldn't open the browser.");
        return false;
      }
    }

    if (!context.mounted) return false;
    return _waitForConnection(context);
  }

  /// Resolves as soon as the connection lands — via the `flaxxapulse://` deep
  /// link (preferred) or status polling (fallback) — or when the user confirms
  /// / cancels in the dialog.
  static Future<bool> _waitForConnection(BuildContext context) async {
    final completer = Completer<bool>();
    Timer? poll;
    Timer? timeout;
    StreamSubscription<Uri>? linkSub;
    var done = false;

    void finish(bool ok) {
      if (done) return;
      done = true;
      poll?.cancel();
      timeout?.cancel();
      linkSub?.cancel();
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      if (!completer.isCompleted) completer.complete(ok);
    }

    // Preferred: the OS re-opens the app on the flaxxapulse:// return.
    try {
      linkSub = AppLinks().uriLinkStream.listen((uri) {
        if (uri.scheme == 'flaxxapulse') {
          finish(uri.queryParameters['connected'] == '1');
        }
      });
    } catch (_) {
      // Deep links unavailable on this platform — polling covers it.
    }

    // Fallback: poll the status endpoint.
    poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (await isConnected()) finish(true);
    });
    timeout = Timer(const Duration(minutes: 2), () => finish(false));

    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connecting Google'),
        content: const Text(
          'Finish signing in to Google in the browser — Pulse will update '
          'automatically. If it doesn\'t, come back and tap "I\'ve connected".',
        ),
        actions: [
          TextButton(
            onPressed: () => finish(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              finish(await isConnected());
            },
            child: const Text("I've connected"),
          ),
        ],
      ),
    ).then((_) {
      if (!done) finish(false);
    });

    return completer.future;
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
