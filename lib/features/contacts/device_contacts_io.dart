import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Device contacts are a mobile-only feature; desktop (also dart:io) reports
/// unsupported so the UI hides the sync affordance there.
bool get deviceContactsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Reads unique, lower-cased email addresses from the device address book,
/// requesting read permission first. Throws [StateError] 'permission_denied'
/// when the user declines.
Future<List<String>> readDeviceContactEmails() async {
  final granted = await FlutterContacts.requestPermission(readonly: true);
  if (!granted) {
    throw StateError('permission_denied');
  }
  final contacts = await FlutterContacts.getContacts(withProperties: true);
  final emails = <String>{};
  for (final c in contacts) {
    for (final e in c.emails) {
      final v = e.address.trim().toLowerCase();
      if (v.contains('@')) emails.add(v);
    }
  }
  return emails.toList();
}
