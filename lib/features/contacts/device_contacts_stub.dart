/// Web / unsupported-platform stub for device contact reading.
bool get deviceContactsSupported => false;

Future<List<String>> readDeviceContactEmails() async =>
    throw UnsupportedError('Device contacts are not available on this platform.');
