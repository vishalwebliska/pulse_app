/// Static app configuration.
///
/// Change [apiBaseUrl] per environment. Notes:
/// - Android emulator reaches your PC's localhost via http://10.0.2.2
/// - A real phone must use your machine's LAN IP (e.g. http://192.168.1.50)
/// - Desktop/web can use the real host once CORS is allowed for web.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = 'https://summaries-aim-librarian-pct.trycloudflare.com';
  static const String apiPrefix = '/api/v1';

  /// Multi-tenancy header expected by the backend (ResolveTenant middleware).
  static const String tenantHeader = 'X-Tenant-ID';
}
