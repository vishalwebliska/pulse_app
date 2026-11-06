// Platform-safe entry point for reading device contact emails.
//
// On mobile (dart:io) this delegates to flutter_contacts; on web it resolves
// to a stub so the web build never imports the native plugin. Desktop also
// resolves to the io variant, which reports unsupported at runtime.
export 'device_contacts_stub.dart'
    if (dart.library.io) 'device_contacts_io.dart';
